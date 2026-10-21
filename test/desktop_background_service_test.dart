import 'dart:io' show Platform;

import 'package:database_data/services/desktop_background_service.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tray and background settings are translated in every language', () {
    const keys = [
      'desktop.background.section',
      'desktop.background.keep_in_tray',
      'desktop.background.keep_in_tray.hint',
      'desktop.background.launch_at_startup',
      'desktop.background.save_failed',
      'desktop.tray.tooltip',
      'desktop.tray.open',
      'desktop.tray.quit',
    ];
    for (final key in keys) {
      final texts = {
        for (final lang in AppLanguage.values)
          lang: Localization.translate(key, lang),
      };
      for (final text in texts.values) {
        expect(text, isNot(key), reason: key);
      }
      expect(
        texts.values.toSet(),
        hasLength(AppLanguage.values.length),
        reason: key,
      );
    }
  });

  test('only the startup entry argument starts hidden in the tray', () {
    expect(
      DesktopBackgroundService.isMinimizedLaunch(const ['--minimized']),
      Platform.isWindows,
    );
    expect(DesktopBackgroundService.isMinimizedLaunch(const []), isFalse);
  });
}
