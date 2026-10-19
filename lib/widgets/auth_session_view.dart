import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Screen/app_workspace_shell.dart';
import '../Screen/subscription_checker.dart';
import '../login_screen.dart';
import '../services/auth_service.dart';
import 'desktop_window_frame.dart';

/// Manages auth state transitions cleanly.
/// When user signs out or switches account, pops any pushed modal routes/screens
/// and transitions between SubscriptionChecker and LoginScreen without tearing down MaterialApp.
class AuthSessionView extends StatefulWidget {
  const AuthSessionView({
    super.key,
    required this.authStateChanges,
    required this.initialUser,
    this.navigatorKey,
    this.builder,
  });

  final Stream<AppAuthUser?> authStateChanges;
  final AppAuthUser? initialUser;
  final GlobalKey<NavigatorState>? navigatorKey;
  final Widget Function(BuildContext, AppAuthUser?)? builder;

  @override
  State<AuthSessionView> createState() => _AuthSessionViewState();
}

class _AuthSessionViewState extends State<AuthSessionView> {
  StreamSubscription<AppAuthUser?>? _subscription;
  AppAuthUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.initialUser;
    _subscription = widget.authStateChanges.listen((user) {
      if (!mounted) return;
      final previousUser = _currentUser;
      if (previousUser?.uid != user?.uid) {
        // Dismiss any modal routes, dialogs or pushed screens back to the root gate
        widget.navigatorKey?.currentState?.popUntil((route) => route.isFirst);
        setState(() {
          _currentUser = user;
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.builder != null) {
      return KeyedSubtree(
        key: ValueKey(_currentUser?.uid),
        child: widget.builder!(context, _currentUser),
      );
    }

    final user = _currentUser;
    if (user != null) {
      const authenticatedContent = SubscriptionChecker();
      Widget desktop() {
        final workspace = context.read<WorkspaceController>();
        return DesktopWindowFrame(
          topBar: const WorkspaceTabStrip(),
          onOpen: (title, icon, screen) =>
              workspace.open(title: title, icon: icon, content: screen),
          child: authenticatedContent,
        );
      }

      final Widget content;
      if (!kIsWeb && Platform.isWindows) {
        content = desktop();
      } else if (kIsWeb) {
        // The website follows the screen: the computer menus on a wide
        // screen, the phone layout on a narrow one.
        content = LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth >= webDesktopMinWidth
              ? desktop()
              : authenticatedContent,
        );
      } else {
        content = authenticatedContent;
      }
      return KeyedSubtree(
        key: ValueKey('authenticated_user_${user.uid}'),
        child: content,
      );
    }

    const loginContent = LoginScreen();
    final content = (!kIsWeb && Platform.isWindows)
        ? const DesktopWindowFrame(child: loginContent)
        : loginContent;
    return KeyedSubtree(
      key: const ValueKey('unauthenticated_login'),
      child: content,
    );
  }
}

/// Width from which the website shows the computer layout (menus and
/// document tabs) instead of the phone layout.
const double webDesktopMinWidth = 1024;
