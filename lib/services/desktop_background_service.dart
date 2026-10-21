import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../settings/app_settings.dart';
import '../settings/localization.dart';

/// Keeps the Windows application alive in the notification area (system
/// tray) when its window is closed, so the Supabase Realtime order events —
/// the only notification path on Windows, where FCM is unavailable — still
/// reach the user as toasts. Also registers the application to start with
/// Windows, hidden in the tray.
class DesktopBackgroundService with WindowListener, TrayListener {
  DesktopBackgroundService._();
  static final DesktopBackgroundService instance = DesktopBackgroundService._();

  /// Passed by the Windows startup entry; the native runner then does not
  /// show the window either (windows/runner/flutter_window.cpp).
  static const String minimizedArgument = '--minimized';

  static const String _keepInTrayKey = 'desktop_keep_in_tray';
  static const String _launchAtStartupKey = 'desktop_launch_at_startup';
  static const String _trayIcon = 'assets/images/tray_icon.ico';

  bool _initialized = false;
  bool _keepInTray = false;
  bool _trayVisible = false;
  bool _startedMinimized = false;

  static bool get isSupported => !kIsWeb && Platform.isWindows;

  bool get keepInTray => _keepInTray;

  /// True when this service decides what closing the window does.
  bool get handlesClose => _initialized;

  /// Whether the process was launched by the Windows startup entry.
  static bool isMinimizedLaunch(List<String> args) =>
      isSupported && args.contains(minimizedArgument);

  Future<void> initialize({required bool startedMinimized}) async {
    if (!isSupported || _initialized) return;
    _initialized = true;
    _startedMinimized = startedMinimized;
    try {
      final prefs = await SharedPreferences.getInstance();
      _keepInTray = prefs.getBool(_keepInTrayKey) ?? false;
      launchAtStartup.setup(
        appName: 'Warchati ERP',
        appPath: Platform.resolvedExecutable,
        args: const [minimizedArgument],
      );
      windowManager.addListener(this);
      trayManager.addListener(this);
      await windowManager.setPreventClose(true);
      await _syncTray();
    } catch (e) {
      debugPrint('DesktopBackground: init failed – $e');
    }
  }

  Future<void> setKeepInTray(bool value) async {
    _keepInTray = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keepInTrayKey, value);
    await _syncTray();
  }

  Future<bool> isLaunchAtStartupEnabled() async {
    if (!isSupported) return false;
    try {
      return await launchAtStartup.isEnabled();
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_launchAtStartupKey) ?? false;
    }
  }

  Future<void> setLaunchAtStartup(bool value) async {
    if (!isSupported) return;
    if (value) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_launchAtStartupKey, value);
  }

  /// Hides the window in the tray when that option is on; quits otherwise.
  Future<void> closeWindow() async {
    if (_keepInTray) {
      await windowManager.hide();
    } else {
      await quit();
    }
  }

  Future<void> showWindow() async {
    if (!_initialized) return;
    try {
      await windowManager.show();
      if (_startedMinimized) {
        // The startup launch never showed the window, so it was never
        // maximized like a normal launch.
        _startedMinimized = false;
        await windowManager.maximize();
      }
      await windowManager.focus();
    } catch (e) {
      debugPrint('DesktopBackground: show failed – $e');
    }
  }

  Future<void> quit() async {
    try {
      await windowManager.setPreventClose(false);
      if (_trayVisible) await trayManager.destroy();
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  /// The tray icon is the only way back to a hidden window, so it exists
  /// whenever the window can be hidden.
  Future<void> _syncTray() async {
    final wanted = _keepInTray || _startedMinimized;
    if (wanted == _trayVisible) return;
    try {
      if (wanted) {
        await trayManager.setIcon(_trayIcon);
        await trayManager.setToolTip(
          Localization.translate(
            'desktop.tray.tooltip',
            await AppSettingsProvider.loadSavedLanguage(),
          ),
        );
      } else {
        await trayManager.destroy();
      }
      _trayVisible = wanted;
    } catch (e) {
      debugPrint('DesktopBackground: tray update failed – $e');
    }
  }

  @override
  void onWindowClose() {
    unawaited(closeWindow());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(showWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    // Rebuilt on every opening so the labels follow the current language.
    unawaited(() async {
      final lang = await AppSettingsProvider.loadSavedLanguage();
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(
              key: 'open',
              label: Localization.translate('desktop.tray.open', lang),
            ),
            MenuItem.separator(),
            MenuItem(
              key: 'quit',
              label: Localization.translate('desktop.tray.quit', lang),
            ),
          ],
        ),
      );
      await trayManager.popUpContextMenu();
    }());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        unawaited(showWindow());
      case 'quit':
        unawaited(quit());
    }
  }
}
