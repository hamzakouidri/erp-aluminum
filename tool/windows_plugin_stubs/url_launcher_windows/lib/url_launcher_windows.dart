library url_launcher_windows;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class UrlLauncherWindows extends UrlLauncherPlatform {
  UrlLauncherWindows({@visibleForTesting Object? api});

  static void registerWith() {
    UrlLauncherPlatform.instance = UrlLauncherWindows();
  }

  @override
  final LinkDelegate? linkDelegate = null;

  @override
  Future<bool> canLaunch(String url) async {
    final uri = Uri.tryParse(url);
    return uri != null && uri.hasScheme;
  }

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    try {
      final result = await Process.run('cmd', ['/c', 'start', '', url]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async {
    return mode == PreferredLaunchMode.platformDefault ||
        mode == PreferredLaunchMode.externalApplication;
  }

  @override
  Future<bool> supportsCloseForMode(PreferredLaunchMode mode) async => false;
}
