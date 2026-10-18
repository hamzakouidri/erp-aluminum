import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every translation key is defined once: the locale maps are merged into one
/// dictionary, where a repeated key silently replaces the earlier text.
void main() {
  test('translation keys are not repeated across locale files', () {
    final keyLine = RegExp(r"""^  (?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)"): \{""");
    final seen = <String, String>{};
    final repeated = <String>[];
    final files = Directory('lib/settings/locales')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      for (final line in file.readAsLinesSync()) {
        final match = keyLine.firstMatch(line);
        if (match == null) continue;
        final key = (match.group(1) ?? match.group(2))!.trim();
        final previous = seen[key];
        if (previous != null) {
          repeated.add('"$key": $previous and ${file.path}');
        } else {
          seen[key] = file.path;
        }
      }
    }
    expect(repeated, isEmpty, reason: repeated.take(20).join('\n'));
  });
}
