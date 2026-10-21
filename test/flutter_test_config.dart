import 'dart:async';
import 'dart:io';

import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';

/// Runs before every test file: the app loads its languages in `main`, so
/// tests load the same JSON files from disk.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  const files = {
    AppLanguage.arabic: 'ar',
    AppLanguage.french: 'fr',
    AppLanguage.english: 'en',
  };
  for (final entry in files.entries) {
    Localization.loadJson(
      entry.key,
      File('assets/i18n/${entry.value}.json').readAsStringSync(),
    );
  }
  await testMain();
}
