import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/cloud_sync_service.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../widgets/desktop_command_bar.dart';
import 'drawer.dart';
import 'settings_screen.dart';
import 'welcom_screen.dart';

const double _workspaceHeaderHeight = 110;

bool get _isWindowsDesktop =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

class WorkspaceEntry {
  final String id;
  final String title;
  final Widget content;
  final IconData icon;
  final Offset position;
  final Size size;
  final bool minimized;
  final bool immersive;

  const WorkspaceEntry({
    required this.id,
    required this.title,
    required this.content,
    required this.icon,
    this.position = const Offset(48, 48),
    this.size = const Size(960, 640),
    this.minimized = false,
    this.immersive = false,
  });

  WorkspaceEntry copyWith({
    String? id,
    String? title,
    Widget? content,
    IconData? icon,
    Offset? position,
    Size? size,
    bool? minimized,
    bool? immersive,
  }) {
    return WorkspaceEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      icon: icon ?? this.icon,
      position: position ?? this.position,
      size: size ?? this.size,
      minimized: minimized ?? this.minimized,
      immersive: immersive ?? this.immersive,
    );
  }
}

class WorkspaceController extends ChangeNotifier {
  static const double _minWindowWidth = 260;
  static const double _minWindowHeight = 220;
  final Map<String, GlobalKey<NavigatorState>> _navigatorKeys = {};

  final List<WorkspaceEntry> _entries = [
    const WorkspaceEntry(
      id: 'home',
      title: 'Home',
      icon: Icons.home_rounded,
      content: WelcomScreen(),
      position: Offset(36, 20),
      size: Size(1100, 720),
    ),
  ];

  int _activeIndex = 0;

  List<WorkspaceEntry> get entries => List.unmodifiable(_entries);

  int get activeIndex => _activeIndex;

  bool get isHomeActive =>
      _entries.isNotEmpty && _entries[_activeIndex].id == 'home';

  GlobalKey<NavigatorState> navigatorKeyFor(String entryId) {
    return _navigatorKeys.putIfAbsent(
      entryId,
      () => GlobalKey<NavigatorState>(debugLabel: 'workspace_nav_$entryId'),
    );
  }

  void open({
    required String title,
    required IconData icon,
    required Widget content,
  }) {
    final existingIndex = _entries.indexWhere((entry) => entry.title == title);
    if (existingIndex != -1) {
      _activeIndex = existingIndex;
      notifyListeners();
      return;
    }

    final index = _entries.length;
    _entries.add(
      WorkspaceEntry(
        id: 'entry_${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        icon: icon,
        content: content,
        position: Offset(24.0 + (index * 20.0), 12.0 + (index * 16.0)),
      ),
    );
    _activeIndex = _entries.length - 1;
    notifyListeners();
  }

  void activate(int index) {
    if (index < 0 || index >= _entries.length) return;
    _activeIndex = index;
    notifyListeners();
  }

  void activateHome() {
    final homeIndex = _entries.indexWhere((entry) => entry.id == 'home');
    if (homeIndex == -1) {
      _entries.insert(
        0,
        const WorkspaceEntry(
          id: 'home',
          title: 'Home',
          icon: Icons.home_rounded,
          content: WelcomScreen(),
          position: Offset(36, 20),
          size: Size(1100, 720),
        ),
      );
      _activeIndex = 0;
      notifyListeners();
      return;
    }

    _activeIndex = homeIndex;
    notifyListeners();
  }

  Future<void> handleBackNavigation() async {
    if (_entries.isEmpty) {
      activateHome();
      return;
    }

    final activeEntry = _entries[_activeIndex];
    final activeNavigator = _navigatorKeys[activeEntry.id]?.currentState;
    if (activeNavigator != null && await activeNavigator.maybePop()) {
      return;
    }

    if (!isHomeActive) {
      activateHome();
    } else {
      notifyListeners();
    }
  }

  void close(int index) {
    if (index < 0 || index >= _entries.length) return;
    final removedEntry = _entries[index];
    _entries.removeAt(index);
    _navigatorKeys.remove(removedEntry.id);

    if (_entries.isEmpty) {
      _entries.add(
        const WorkspaceEntry(
          id: 'home',
          title: 'Home',
          icon: Icons.home_rounded,
          content: WelcomScreen(),
          position: Offset(36, 20),
          size: Size(1100, 720),
        ),
      );
      _activeIndex = 0;
      notifyListeners();
      return;
    }

    if (_activeIndex > index) {
      _activeIndex -= 1;
    } else if (_activeIndex >= _entries.length) {
      _activeIndex = _entries.length - 1;
    }
    notifyListeners();
  }

  bool _isOsChatHeadMode = false;
  bool get isOsChatHeadMode => _isOsChatHeadMode;

  Future<void> minimizeToOsChatHead() async {}
  Future<void> restoreFromOsChatHead() async {}
  void minimize(int index) {}

  void move(int index, Offset delta) {
    if (index < 0 || index >= _entries.length) return;
    final current = _entries[index];
    _entries[index] = current.copyWith(position: current.position + delta);
    notifyListeners();
  }

  void resize(int index, Offset delta) {
    if (index < 0 || index >= _entries.length) return;
    final current = _entries[index];
    final nextWidth = (current.size.width + delta.dx).clamp(
      _minWindowWidth,
      1600.0,
    );
    final nextHeight = (current.size.height + delta.dy).clamp(
      _minWindowHeight,
      1200.0,
    );
    _entries[index] = current.copyWith(size: Size(nextWidth, nextHeight));
    notifyListeners();
  }

  void setWindowBounds(
    int index, {
    Size? size,
    Offset? position,
    bool? minimized,
    bool? immersive,
  }) {
    if (index < 0 || index >= _entries.length) return;
    final current = _entries[index];
    _entries[index] = current.copyWith(
      size: size ?? current.size,
      position: position ?? current.position,
      minimized: minimized ?? current.minimized,
      immersive: immersive ?? current.immersive,
    );
    _activeIndex = index;
    notifyListeners();
  }

  void setImmersive(int index, bool immersive) {
    if (index < 0 || index >= _entries.length) return;
    _entries[index] = _entries[index].copyWith(
      immersive: immersive,
      minimized: false,
    );
    _activeIndex = index;
    notifyListeners();
  }
}

WorkspaceEntry _fitEntryToCanvas(WorkspaceEntry entry, Size canvasSize) {
  const edgeInset = 4.0;
  final maxWidth = canvasSize.width <= 420
      ? canvasSize.width - (edgeInset * 2)
      : canvasSize.width * 0.96;
  final maxHeight = canvasSize.height <= 700
      ? canvasSize.height - (edgeInset * 2)
      : canvasSize.height * 0.96;
  final width = entry.size.width.clamp(
    260.0,
    maxWidth > 260 ? maxWidth : 260.0,
  );
  final height = entry.size.height.clamp(
    220.0,
    maxHeight > 220 ? maxHeight : 220.0,
  );
  final left = entry.position.dx.clamp(
    edgeInset,
    canvasSize.width - width - edgeInset < edgeInset
        ? edgeInset
        : canvasSize.width - width - edgeInset,
  );
  final top = entry.position.dy.clamp(
    edgeInset,
    canvasSize.height - height - edgeInset < edgeInset
        ? edgeInset
        : canvasSize.height - height - edgeInset,
  );

  return entry.copyWith(size: Size(width, height), position: Offset(left, top));
}

void openAdaptiveScreen(
  BuildContext context, {
  required String title,
  required IconData icon,
  required Widget screen,
}) {
  final settings = Provider.of<AppSettingsProvider>(context, listen: false);
  final liveScreen = _CloudDataRefreshBoundary(child: screen);
  if (settings.viewMode == AppViewMode.classic) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (routeCtx) => liveScreen));
    return;
  }

  final workspace = Provider.of<WorkspaceController>(context, listen: false);
  workspace.open(title: title, icon: icon, content: liveScreen);
}

/// Keeps the current route open but recreates its data screen after a complete
/// cloud restore. Local edits emit other events and never reset the page.
class _CloudDataRefreshBoundary extends StatefulWidget {
  const _CloudDataRefreshBoundary({required this.child});

  final Widget child;

  @override
  State<_CloudDataRefreshBoundary> createState() =>
      _CloudDataRefreshBoundaryState();
}

class _CloudDataRefreshBoundaryState extends State<_CloudDataRefreshBoundary> {
  StreamSubscription<String>? _subscription;
  Timer? _debounce;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _subscription = CloudSyncService().dbUpdateStream.listen((event) {
      if (event != 'cloud_restored' && event != 'catalog_downloaded') return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 80), () {
        if (!mounted) return;
        setState(() => _revision++);
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: ValueKey<int>(_revision), child: widget.child);
  }
}

class AppWorkspaceShell extends StatelessWidget {
  const AppWorkspaceShell({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);

    // The Windows shell is intentionally unified: permanent document tabs on
    // the first row and the command menu on the second row.
    if (_isWindowsDesktop) {
      return const _TabbedWorkspaceView();
    }

    switch (settings.viewMode) {
      case AppViewMode.classic:
        return const WelcomScreen();
      case AppViewMode.tabs:
        return const _TabbedWorkspaceView();
      case AppViewMode.windows:
        return const _FloatingWorkspaceView();
      default:
        return const WelcomScreen();
    }
  }
}

class _WorkspaceContentHost extends StatelessWidget {
  final WorkspaceEntry entry;
  final bool active;

  const _WorkspaceContentHost({
    super.key,
    required this.entry,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final navigatorKey = Provider.of<WorkspaceController>(
      context,
      listen: false,
    ).navigatorKeyFor(entry.id);

    return Navigator(
      key: navigatorKey,
      onGenerateInitialRoutes: (_, __) {
        return [
          MaterialPageRoute(
            builder: (_) => entry.content,
            settings: RouteSettings(name: entry.id),
          ),
        ];
      },
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  final String modeTitle;
  final String modeSubtitle;
  final Widget? bottom;
  final VoidCallback? onToggleSidebar;
  final bool isSidebarOpen;

  const _WorkspaceHeader({
    required this.modeTitle,
    required this.modeSubtitle,
    this.bottom,
    this.onToggleSidebar,
    this.isSidebarOpen = true,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: StreamBuilder<DocumentSnapshot>(
          stream: user == null
              ? null
              : FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .snapshots(),
          builder: (context, snapshot) {
            final data = snapshot.data?.data() as Map<String, dynamic>?;
            final workshopName = data?['workshopName'] ?? 'ورشة الألمنيوم';
            final String displayName =
                (data?['displayName'] as String?)?.trim().isNotEmpty == true
                ? data!['displayName'].toString()
                : (user?.displayName?.trim().isNotEmpty == true
                      ? user!.displayName!
                      : (data?['role'] == 'manager' ? 'مدير الورشة' : 'عامل'));
            final logoUrl = data?['workshopLogoUrl'] ?? data?['logoUrl'];

            final safeWorkshopName =
                workshopName?.toString().trim().isNotEmpty == true
                ? workshopName.toString()
                : 'ورشة الألمنيوم';
            final safeDisplayName = displayName?.toString() ?? '';

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Builder(
                        builder: (innerContext) => IconButton(
                          tooltip: isSidebarOpen ? 'إغلاق القائمة' : 'فتح القائمة',
                          onPressed: onToggleSidebar ?? () => Scaffold.of(innerContext).openDrawer(),
                          icon: Icon(
                            onToggleSidebar != null
                                ? (isSidebarOpen ? Icons.menu_open_rounded : Icons.menu_rounded)
                                : Icons.menu_rounded,
                            color: Colors.white,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.white,
                        child: Text(
                          safeWorkshopName.length >= 2
                              ? safeWorkshopName.substring(0, 2).toUpperCase()
                              : safeWorkshopName.toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF1D4ED8),
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              safeWorkshopName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              safeDisplayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFD6E4FF),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          openAdaptiveScreen(
                            context,
                            title: 'الإعدادات',
                            icon: Icons.settings,
                            screen: const SettingsScreen(),
                          );
                        },
                        icon: const Icon(
                          Icons.settings_rounded,
                          color: Colors.white,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              modeTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              modeSubtitle,
                              style: const TextStyle(
                                color: Color(0xFFBFDBFE),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (bottom != null) ...[const SizedBox(height: 14), bottom!],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HomeTabBrandContent extends StatefulWidget {
  final bool active;
  const _HomeTabBrandContent({required this.active});

  @override
  State<_HomeTabBrandContent> createState() => _HomeTabBrandContentState();
}

class _HomeTabBrandContentState extends State<_HomeTabBrandContent> {
  String _workshopName = 'ورشة الألمنيوم';
  String? _logoUrl;
  ImageProvider? _cachedLogo;

  @override
  void initState() {
    super.initState();
    _loadLocalProfile();
  }

  Future<void> _loadLocalProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString('workshop_name');
      final savedLogo = prefs.getString('workshop_logo_base64');
      if (mounted) {
        setState(() {
          if (savedName != null && savedName.isNotEmpty) _workshopName = savedName;
          if (savedLogo != null && savedLogo.isNotEmpty) {
            _logoUrl = savedLogo;
            _updateLogoProvider(savedLogo);
          }
        });
      }
    } catch (_) {}
  }

  void _updateLogoProvider(String? url) {
    if (url == null || url.isEmpty) {
      _cachedLogo = null;
      return;
    }
    if (url.startsWith('http')) {
      _cachedLogo = NetworkImage(url);
    } else {
      try {
        final clean = url.contains(',') ? url.split(',').last : url;
        final bytes = base64Decode(clean);
        if (bytes.isNotEmpty) {
          _cachedLogo = MemoryImage(bytes);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return StreamBuilder<DocumentSnapshot>(
      stream: user == null
          ? null
          : FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data?.data() != null) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final firestoreName = (data['workshopName'] as String?)?.trim();
          final firestoreLogo = (data['workshopLogoUrl'] as String?)?.isNotEmpty == true
              ? data['workshopLogoUrl']
              : data['logoUrl'];

          if (firestoreName != null && firestoreName.isNotEmpty) {
            _workshopName = firestoreName;
          }
          if (firestoreLogo != null && firestoreLogo.isNotEmpty) {
            _logoUrl = firestoreLogo;
            _updateLogoProvider(firestoreLogo);
          }
        }

        Widget iconWidget;
        if (_cachedLogo != null) {
          iconWidget = Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              image: DecorationImage(
                image: _cachedLogo!,
                fit: BoxFit.cover,
              ),
              border: Border.all(
                color: widget.active ? const Color(0xFF0F172A) : Colors.white,
                width: 1,
              ),
            ),
          );
        } else {
          iconWidget = Icon(
            Icons.apps_rounded,
            size: 18,
            color: widget.active ? const Color(0xFF2563EB) : Colors.white,
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Text(
                _workshopName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  color: widget.active ? const Color(0xFF0F172A) : Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HeaderWorkshopBrand extends StatefulWidget {
  const _HeaderWorkshopBrand();

  @override
  State<_HeaderWorkshopBrand> createState() => _HeaderWorkshopBrandState();
}

class _HeaderWorkshopBrandState extends State<_HeaderWorkshopBrand> {
  String _workshopName = 'ورشة الألمنيوم';
  String? _logoUrl;
  ImageProvider? _cachedLogo;

  @override
  void initState() {
    super.initState();
    _loadLocalProfile();
  }

  Future<void> _loadLocalProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString('workshop_name');
      final savedLogo = prefs.getString('workshop_logo_base64');
      if (mounted) {
        setState(() {
          if (savedName != null && savedName.isNotEmpty) _workshopName = savedName;
          if (savedLogo != null && savedLogo.isNotEmpty) {
            _logoUrl = savedLogo;
            _updateLogoProvider(savedLogo);
          }
        });
      }
    } catch (_) {}
  }

  void _updateLogoProvider(String? url) {
    if (url == null || url.isEmpty) {
      _cachedLogo = null;
      return;
    }
    if (url.startsWith('http')) {
      _cachedLogo = NetworkImage(url);
    } else {
      try {
        final clean = url.contains(',') ? url.split(',').last : url;
        final bytes = base64Decode(clean);
        if (bytes.isNotEmpty) {
          _cachedLogo = MemoryImage(bytes);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return StreamBuilder<DocumentSnapshot>(
      stream: user == null
          ? null
          : FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data?.data() != null) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final firestoreName = (data['workshopName'] as String?)?.trim();
          final firestoreLogo = (data['workshopLogoUrl'] as String?)?.isNotEmpty == true
              ? data['workshopLogoUrl']
              : data['logoUrl'];

          if (firestoreName != null && firestoreName.isNotEmpty) {
            _workshopName = firestoreName;
          }
          if (firestoreLogo != null && firestoreLogo != _logoUrl) {
            _logoUrl = firestoreLogo;
            _updateLogoProvider(firestoreLogo);
          }
        }

        final initial = _workshopName.length >= 2
            ? _workshopName.substring(0, 2).toUpperCase()
            : _workshopName.toUpperCase();

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFF2563EB),
                backgroundImage: _cachedLogo,
                child: _cachedLogo == null
                    ? Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          fontFamily: 'Cairo',
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  _workshopName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TabbedWorkspaceView extends StatefulWidget {
  const _TabbedWorkspaceView();

  @override
  State<_TabbedWorkspaceView> createState() => _TabbedWorkspaceViewState();
}

class _TabbedWorkspaceViewState extends State<_TabbedWorkspaceView> {
  bool _isSidebarOpen = true;

  @override
  Widget build(BuildContext context) {
    final workspace = Provider.of<WorkspaceController>(context);
    final isDesktop = _isWindowsDesktop || MediaQuery.of(context).size.width >= 900;

    final mainContent = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        workspace.handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFEAF1FB),
        drawer: isDesktop ? null : const AppDrawer(),
        body: Column(
          children: [
            Container(
              color: const Color(0xFF0F172A),
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: 60,
                  child: Row(
                    children: [
                      Builder(
                        builder: (menuContext) => IconButton(
                          tooltip: _isSidebarOpen ? 'إغلاق القائمة' : 'فتح القائمة',
                          onPressed: () {
                            if (isDesktop) {
                              setState(() => _isSidebarOpen = !_isSidebarOpen);
                            } else {
                              Scaffold.of(menuContext).openDrawer();
                            }
                          },
                          icon: Icon(
                            isDesktop
                                ? (_isSidebarOpen ? Icons.menu_open_rounded : Icons.menu_rounded)
                                : Icons.menu_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsetsDirectional.fromSTEB(
                            isDesktop ? 0 : 8,
                            10,
                            12,
                            0,
                          ),
                          scrollDirection: Axis.horizontal,
                          itemCount: workspace.entries.length,
                          itemBuilder: (context, index) {
                            final entry = workspace.entries[index];
                            final active = index == workspace.activeIndex;

                            return GestureDetector(
                              onTap: () {
                                workspace.activate(index);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsetsDirectional.only(end: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(
                                  color: active
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.14),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(14),
                                    bottom: Radius.circular(6),
                                  ),
                                  border: Border.all(
                                    color: active
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.18),
                                    width: active ? 1.5 : 1,
                                  ),
                                ),
                                child: entry.id == 'home'
                                    ? _HomeTabBrandContent(active: active)
                                    : Row(
                                        children: [
                                          Icon(
                                            entry.icon,
                                            size: 17,
                                            color: active
                                                ? const Color(0xFF0F172A)
                                                : Colors.white,
                                          ),
                                          const SizedBox(width: 8),
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(maxWidth: 190),
                                            child: Text(
                                              Localization.translate(
                                                entry.title,
                                                Provider.of<AppSettingsProvider>(
                                                  context,
                                                ).language,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: active
                                                    ? const Color(0xFF0F172A)
                                                    : Colors.white,
                                              ),
                                            ),
                                          ),
                                          if (entry.id != 'home') ...[
                                            const SizedBox(width: 10),
                                            InkWell(
                                              onTap: () => workspace.close(index),
                                              child: Icon(
                                                Icons.close_rounded,
                                                size: 16,
                                                color: active
                                                    ? const Color(0xFF0F172A)
                                                    : Colors.white,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_isWindowsDesktop)
              DesktopCommandBar(
                onOpen: (title, icon, screen) => openAdaptiveScreen(
                  context,
                  title: title,
                  icon: icon,
                  screen: screen,
                ),
              ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: 0.96,
                        end: 1.0,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  key: const ValueKey('expanded_content'),
                  width: double.infinity,
                  color: const Color(0xFFEAF1FB),
                  child: IndexedStack(
                    index: workspace.activeIndex,
                    children: workspace.entries.asMap().entries.map((mapped) {
                      return _WorkspaceContentHost(
                        key: ValueKey('tab_${mapped.value.id}'),
                        entry: mapped.value,
                        active: mapped.key == workspace.activeIndex,
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (isDesktop) {
      return Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.fastOutSlowIn,
            width: _isSidebarOpen ? 310 : 0,
            child: _isSidebarOpen
                ? const Material(
                    elevation: 6,
                    child: AppDrawer(),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(child: mainContent),
        ],
      );
    }

    return mainContent;
  }
}

class _FloatingWorkspaceView extends StatefulWidget {
  const _FloatingWorkspaceView();

  @override
  State<_FloatingWorkspaceView> createState() => _FloatingWorkspaceViewState();
}

class _FloatingWorkspaceViewState extends State<_FloatingWorkspaceView> {
  bool _isSidebarOpen = true;

  @override
  Widget build(BuildContext context) {
    final workspace = Provider.of<WorkspaceController>(context);
    final isDesktop = _isWindowsDesktop || MediaQuery.of(context).size.width >= 900;
    final immersiveIndex = workspace.entries.indexWhere(
      (entry) => entry.immersive,
    );
    final visibleEntries = workspace.entries.asMap().entries.toList();
    visibleEntries.sort((a, b) {
      if (a.key == workspace.activeIndex) return 1;
      if (b.key == workspace.activeIndex) return -1;
      return 0;
    });

    final mainContent = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        workspace.handleBackNavigation();
      },
      child: Scaffold(
        drawer: isDesktop ? null : AppDrawer(),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final headerHeight = immersiveIndex == -1
                ? _workspaceHeaderHeight + (_isWindowsDesktop ? 48.0 : 0.0)
                : 0.0;
            final canvasSize = Size(
              constraints.maxWidth,
              constraints.maxHeight - headerHeight,
            );

            final workspaceArea = Container(
              decoration: const BoxDecoration(color: Color(0xFFDCE7F8)),
              child: Stack(
                children: [
                  for (final mapped in visibleEntries)
                    if (immersiveIndex == -1 || mapped.key == immersiveIndex)
                      Builder(
                        builder: (context) {
                          final fittedEntry = immersiveIndex == mapped.key
                              ? mapped.value.copyWith(
                                  position: Offset.zero,
                                  size: canvasSize,
                                )
                              : _fitEntryToCanvas(mapped.value, canvasSize);
                          return Positioned(
                            left: fittedEntry.position.dx,
                            top: fittedEntry.position.dy,
                            width: fittedEntry.size.width,
                            height: fittedEntry.size.height,
                            child: _WindowFrame(
                              entry: fittedEntry,
                              active: mapped.key == workspace.activeIndex,
                              immersive: immersiveIndex == mapped.key,
                              onTap: () => workspace.activate(mapped.key),
                              onClose: () => workspace.close(mapped.key),
                              onMinimize: () => workspace.minimize(mapped.key),
                              onCompact: () {
                                const compactSize = Size(220, 220);
                                final compactEntry = _fitEntryToCanvas(
                                  fittedEntry.copyWith(
                                    size: compactSize,
                                    immersive: false,
                                  ),
                                  canvasSize,
                                );
                                workspace.setWindowBounds(
                                  mapped.key,
                                  size: compactEntry.size,
                                  position: compactEntry.position,
                                  minimized: false,
                                  immersive: false,
                                );
                              },
                              onFullscreen: () {
                                final fullscreenEntry = _fitEntryToCanvas(
                                  fittedEntry.copyWith(
                                    size: Size(
                                      canvasSize.width,
                                      canvasSize.height,
                                    ),
                                    position: Offset.zero,
                                    immersive: false,
                                  ),
                                  canvasSize,
                                );
                                workspace.setWindowBounds(
                                  mapped.key,
                                  size: fullscreenEntry.size,
                                  position: fullscreenEntry.position,
                                  minimized: false,
                                  immersive: false,
                                );
                              },
                              onImmersiveToggle: () => workspace.setImmersive(
                                mapped.key,
                                immersiveIndex != mapped.key,
                              ),
                              onDrag: (delta) =>
                                  workspace.move(mapped.key, delta),
                              onResize: (delta) =>
                                  workspace.resize(mapped.key, delta),
                            ),
                          );
                        },
                      ),
                ],
              ),
            );

            if (immersiveIndex != -1) {
              return workspaceArea;
            }

            return Column(
              children: [
                _WorkspaceHeader(
                  modeTitle: 'نظام النوافذ',
                  modeSubtitle: 'الشريط العلوي ثابت وواضح والنوافذ تظهر تحته',
                  onToggleSidebar: isDesktop ? () => setState(() => _isSidebarOpen = !_isSidebarOpen) : null,
                  isSidebarOpen: _isSidebarOpen,
                ),
                if (_isWindowsDesktop)
                  DesktopCommandBar(
                    onOpen: (title, icon, screen) => openAdaptiveScreen(
                      context,
                      title: title,
                      icon: icon,
                      screen: screen,
                    ),
                  ),
                Expanded(child: workspaceArea),
              ],
            );
          },
        ),
      ),
    );

    if (isDesktop) {
      return Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.fastOutSlowIn,
            width: _isSidebarOpen ? 310 : 0,
            child: _isSidebarOpen
                ? const Material(
                    elevation: 6,
                    child: AppDrawer(),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(child: mainContent),
        ],
      );
    }

    return mainContent;
  }
}

class _WindowFrame extends StatefulWidget {
  final WorkspaceEntry entry;
  final bool active;
  final bool immersive;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final VoidCallback onCompact;
  final VoidCallback onFullscreen;
  final VoidCallback onImmersiveToggle;
  final ValueChanged<Offset> onDrag;
  final ValueChanged<Offset> onResize;

  const _WindowFrame({
    super.key,
    required this.entry,
    required this.active,
    required this.immersive,
    required this.onTap,
    required this.onClose,
    required this.onMinimize,
    required this.onCompact,
    required this.onFullscreen,
    required this.onImmersiveToggle,
    required this.onDrag,
    required this.onResize,
  });

  @override
  State<_WindowFrame> createState() => _WindowFrameState();
}

class _WindowFrameState extends State<_WindowFrame> {
  late Size _scaleStartSize;
  late Size _lastScaleAppliedSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: widget.onTap,
        onScaleStart: (_) {
          _scaleStartSize = widget.entry.size;
          _lastScaleAppliedSize = widget.entry.size;
          widget.onTap();
        },
        onScaleUpdate: (details) {
          if (details.scale == 1.0) return;
          final targetSize = Size(
            _scaleStartSize.width * details.scale,
            _scaleStartSize.height * details.scale,
          );
          final delta = Offset(
            targetSize.width - _lastScaleAppliedSize.width,
            targetSize.height - _lastScaleAppliedSize.height,
          );
          if (delta.dx.abs() < 0.8 && delta.dy.abs() < 0.8) return;
          widget.onResize(delta);
          _lastScaleAppliedSize = targetSize;
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(widget.immersive ? 0 : 18),
            border: Border.all(
              color: widget.immersive
                  ? Colors.transparent
                  : widget.active
                  ? Colors.blue.shade300
                  : Colors.blueGrey.shade100,
              width: widget.immersive ? 0 : (widget.active ? 2 : 1),
            ),
            boxShadow: widget.immersive
                ? const []
                : [
                    BoxShadow(
                      color: widget.active
                          ? Colors.blue.withValues(alpha: 0.18)
                          : Colors.black12,
                      blurRadius: widget.active ? 18 : 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Column(
            children: [
              GestureDetector(
                onTap: widget.onTap,
                onPanUpdate: widget.immersive
                    ? null
                    : (details) => widget.onDrag(details.delta),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: widget.active
                        ? const Color(0xFF0F172A)
                        : Colors.blueGrey.shade700,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(widget.immersive ? 0 : 16),
                      topRight: Radius.circular(widget.immersive ? 0 : 16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(widget.entry.icon, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          Localization.translate(
                            widget.entry.title,
                            Provider.of<AppSettingsProvider>(
                              context,
                              listen: false,
                            ).language,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: widget.onCompact,
                        icon: const Icon(
                          Icons.fit_screen_rounded,
                          color: Colors.white,
                        ),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'مربع صغير',
                      ),
                      IconButton(
                        onPressed: widget.onFullscreen,
                        icon: const Icon(
                          Icons.zoom_out_map_rounded,
                          color: Colors.white,
                        ),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'تكبير داخل المساحة',
                      ),
                      IconButton(
                        onPressed: widget.onImmersiveToggle,
                        icon: Icon(
                          widget.immersive
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          color: Colors.white,
                        ),
                        visualDensity: VisualDensity.compact,
                        tooltip: widget.immersive
                            ? 'إغلاق ملء الشاشة'
                            : 'ملء شاشة الهاتف',
                      ),

                      if (widget.entry.id != 'home')
                        IconButton(
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close, color: Colors.white),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'إغلاق',
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(widget.immersive ? 0 : 16),
                    bottomRight: Radius.circular(widget.immersive ? 0 : 16),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _WorkspaceContentHost(
                          key: ValueKey('window_${widget.entry.id}'),
                          entry: widget.entry,
                          active: widget.active,
                        ),
                      ),
                      if (!widget.immersive)
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onTap,
                            onPanUpdate: (details) =>
                                widget.onResize(details.delta),
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.96),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.open_with_rounded,
                                size: 16,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
